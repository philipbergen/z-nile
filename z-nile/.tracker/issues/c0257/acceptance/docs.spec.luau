--!strict
-- c0257 AC6: the documents say how to install and test the plugin, with a test command that runs on node 22 (a folder argument
-- fails there), and the restated rules move with the change: SETUP.md's rows, z-nile's README line and zz-rules' deploy sentence.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds the edited files (prep proved these specs against the prototype that way)
local TREE = process.env.ZN_C0257_TREE or TOP
local APP = `{TREE}/z-nile-omarchy/znile.board`

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- a `node --test` whose argument is a folder (ends in tests or tests/)
local function folderForm(text: string): boolean
	return string.find(text, "node %-%-test [^%s`]*tests/?[%s`]") ~= nil
		or string.find(text, "node %-%-test [^%s`]*tests/?$") ~= nil
end

return t.spec("c0257 AC6: the documented commands", function(it)
	it("AC6: the matcher sees the folder form and not the file form", function()
		t.expect(folderForm("`node --test z-nile-omarchy/znile.board/tests/`")).toBe(true)
		t.expect(folderForm("Tests: `node --test tests/`")).toBe(true)
		t.expect(folderForm("//   node --test ~/.config/omarchy/plugins/znile.board/tests/\n")).toBe(true)
		t.expect(folderForm("node --test tests")).toBe(true)
		t.expect(folderForm("`node --test tests/model.test.mjs`")).toBe(false)
	end)

	it(
		"AC6: the test command is the file path in the top README, the plugin's README and the test's own header",
		function()
			local top = fs.readFile(`{TREE}/z-nile-omarchy/README.md`)
			local inner = fs.readFile(`{APP}/README.md`)
			local header = fs.readFile(`{APP}/tests/model.test.mjs`)
			t.expect(has(top, "`node --test z-nile-omarchy/znile.board/tests/model.test.mjs`")).toBe(true)
			t.expect(has(inner, "`node --test tests/model.test.mjs`")).toBe(true)
			t.expect(has(header, "//   node --test tests/model.test.mjs")).toBe(true)
			for _, text in { top, inner, header } do
				t.expect(folderForm(text)).toBe(false)
			end
			t.expect(has(top, "omarchy plugin enable znile.board")).toBe(true)
			t.expect(has(top, "settings.json")).toBe(true)
		end
	)

	it(
		"AC6: SETUP.md, z-nile's README and zz-rules say what the app needs and where the deploy list ends",
		function()
			local setup = fs.readFile(`{TREE}/SETUP.md`)
			t.expect(has(setup, "| Python 3 (`python3`) |")).toBe(true)
			t.expect(has(setup, "The full gate needs it: the omarchy board app's `fetch.sh` runs it"))
				.toBe(true)
			t.expect(has(setup, "| Omarchy board app (optional, an omarchy machine) |")).toBe(true)
			local readme = fs.readFile(`{TREE}/z-nile/README.md`)
			t.expect(has(readme, "- **The omarchy board app.** `z-nile-omarchy/znile.board/` (c0257)"))
				.toBe(true)
			local rules = fs.readFile(`{TREE}/z-nile/skills/zz-rules/SKILL.md`)
			t.expect(has(rules, "and `z-nile/next` on `push`. It also ignores `z-nile-omarchy/**` (c0257"))
				.toBe(true)
			t.expect(has(rules, "after the roots and before `z-nile/next`.")).toBe(true)
		end
	)
end)
